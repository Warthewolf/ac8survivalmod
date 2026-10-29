"""build_hash_test.py <build_hash_test.exe> <work folder> (run by tools/checks/build_hash_test.sh): the build hash and the
run's HMAC worked out by the runtime's own code (runtime/build_hash.c, compiled into the exe) and by tools/build_hash.py /
Python's hmac must agree, on a small made-up mod tree: scripts in mixed case, a non-ASCII name, a file larger than a read
chunk, things that aren't hashed (another extension, a folder named like a script, the player's survival.ini), a byte
changed, a survival_config.lua added, a file missing. Made-up keys only."""
import hashlib
import hmac
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import build_hash  # noqa: E402  (tools/build_hash.py)

EXE, WORK = sys.argv[1], sys.argv[2]
fails = 0


def check(ok, what):
    global fails
    print(('  ok   ' if ok else '  FAIL ') + what)
    if not ok:
        fails += 1


def write(rel, data):
    p = os.path.join(WORK, 'Mods', *rel.split('/'))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:
        f.write(data if isinstance(data, bytes) else data.encode('utf-8'))
    return p


def native(*args):
    out = subprocess.run([EXE, *args], cwd=WORK, capture_output=True, text=True, encoding='utf-8', errors='replace',
                         creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    return out.stdout.strip()


def c_hash():
    out = native('hash', 'Mods')
    first = out.splitlines()[0] if out else ''
    return first[5:] if first.startswith('hash ') and 'FAILED' not in first else first


def py_hash():
    try:
        return build_hash.build_hash(os.path.join(WORK, 'Mods'))
    except SystemExit as e:
        return f'FAILED {e}'


shutil.rmtree(os.path.join(WORK, 'Mods'), ignore_errors=True)
write('AC8SurvivalMode/Scripts/main.lua', 'VERSION = "0.0.1-coop.1"\n')
write('AC8SurvivalMode/Scripts/sv_core.lua', '-- core\nlocal x = 1\n')
write('AC8SurvivalMode/Scripts/Zeta.LUA', 'return 3\n')
write('AC8SurvivalMode/Scripts/beta.lua', 'return 2\n')
write('AC8SurvivalMode/Scripts/Ünicöde.lua', 'return "ü"\n')
write('AC8SurvivalMode/Scripts/notes.txt', 'not hashed\n')
write('AC8SurvivalMode/Scripts/sv_old.lua.bak', 'not hashed\n')
os.makedirs(os.path.join(WORK, 'Mods', 'AC8SurvivalMode', 'Scripts', 'folder.lua'), exist_ok=True)
write('AC8SurvivalMode/Scripts/ai/LA_SV_Two.lua', 'return {}\n')
write('AC8SurvivalMode/Scripts/ai/LA_SV_One.lua', 'return {1}\n')
write('AC8SurvivalMode/config/survival.default.ini', '[rounds]\n;start_round = 1\n')
write('AC8SurvivalMode/config/survival.ini', '[rounds]\nstart_round = 5\n')
write('AC8SurvivalMode/dlls/main.dll', bytes(range(256)) * 40)
write('IoStoreLoaderMod/SurvivalMode/SurvivalMode_P.utoc', b'-==--==--==--==-' + bytes(500))
big = hashlib.sha256(b'seed').digest() * 6000                         # (192000 bytes: three read chunks)
write('IoStoreLoaderMod/SurvivalMode/SurvivalMode_P.ucas', big)

base_c, base_py = c_hash(), py_hash()
listing = []
build_hash.build_hash(os.path.join(WORK, 'Mods'), listing)
names = [n for n, _ in listing]
check(len(base_c) == 64 and base_c == base_py, f'the runtime and build_hash.py agree: {base_c[:16]}... / {base_py[:16]}...')
check(names[:5] == ['ac8survivalmode/scripts/beta.lua', 'ac8survivalmode/scripts/main.lua', 'ac8survivalmode/scripts/sv_core.lua',
                    'ac8survivalmode/scripts/zeta.lua', 'ac8survivalmode/scripts/Ünicöde.lua'],
      'scripts by lowercased name in byte order, non-ASCII letters kept: ' + ', '.join(n.split('/')[-1] for n in names[:5]))
check(names[5:7] == ['ac8survivalmode/scripts/ai/la_sv_one.lua', 'ac8survivalmode/scripts/ai/la_sv_two.lua'], 'then the behaviour scripts')
check(names[7:] == ['ac8survivalmode/config/survival.default.ini', 'ac8survivalmode/dlls/main.dll',
                    'iostoreloadermod/survivalmode/survivalmode_p.utoc', 'iostoreloadermod/survivalmode/survivalmode_p.ucas'],
      'then the ini, main.dll and the container')
info = native('hash', 'Mods').splitlines()
check(len(info) > 1 and info[1].startswith('files 11 scripts 5 ai 2'), f'the runtime hashed 11 files, 5 scripts and 2 behaviour scripts ({info[1:] or "?"})')

# what isn't hashed changes nothing
write('AC8SurvivalMode/config/survival.ini', '[rounds]\nstart_round = 9\n')
write('AC8SurvivalMode/Scripts/readme.md', 'x')
write('AC8SurvivalMode/AC8SurvivalMode_lua.log', 'log')
check(c_hash() == base_c and py_hash() == base_c, 'survival.ini, other files and logs: the same hash')

# a byte changed in a script: a new hash, both agree
p = write('AC8SurvivalMode/Scripts/sv_core.lua', '-- core\nlocal x = 2\n')
h1c, h1p = c_hash(), py_hash()
check(h1c != base_c and h1c == h1p, 'a script edited: another hash, the same both ways')
write('AC8SurvivalMode/Scripts/sv_core.lua', '-- core\nlocal x = 1\n')
check(c_hash() == base_c, 'put back: the release hash again')

# a survival_config.lua dropped in
cfg = write('AC8SurvivalMode/Scripts/survival_config.lua', 'return { start_round = 20 }\n')
h2c, h2p = c_hash(), py_hash()
check(h2c != base_c and h2c == h2p, 'survival_config.lua added: another hash, the same both ways')
os.remove(cfg)

# the container's last byte
write('IoStoreLoaderMod/SurvivalMode/SurvivalMode_P.ucas', big[:-1] + bytes([big[-1] ^ 1]))
h3c, h3p = c_hash(), py_hash()
check(h3c != base_c and h3c == h3p, 'one bit of the container: another hash, the same both ways')
write('IoStoreLoaderMod/SurvivalMode/SurvivalMode_P.ucas', big)

# a required file missing
dll = os.path.join(WORK, 'Mods', 'AC8SurvivalMode', 'dlls', 'main.dll')
os.rename(dll, dll + '.off')
m = native('hash', 'Mods')
check(m.startswith('hash FAILED missing main.dll') and py_hash().startswith('FAILED'), f'main.dll missing: no hash ({m})')
os.rename(dll + '.off', dll)
check(c_hash() == base_c, 'back: the release hash again')

# the run's signature: HMAC-SHA256(key, "<build>\n<body>"), and the body alone as before 0.28.6
KEY, BODY = 'made-up-test-key-not-the-real-one', '{"v":1,"run_id":"abc","mod":"0.72.2-coop.20"}'
want = hmac.new(KEY.encode(), f'{base_c}\n{BODY}'.encode(), hashlib.sha256).hexdigest()
got = native('hmac', KEY, base_c, BODY)
check(got == 'hmac ' + want, f'the signature over build + body: {got[5:21]}... / {want[:16]}...')
want0 = hmac.new(KEY.encode(), BODY.encode(), hashlib.sha256).hexdigest()
check(native('hmac', KEY, '-', BODY) == 'hmac ' + want0, 'the signature over the body alone (older Workers)')

print('build hash test: ' + (f'{fails} FAILED' if fails else 'all passed'))
sys.exit(1 if fails else 0)
